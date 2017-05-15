function b = assemble_RHS_RayFEM_with_ST(node,elem,xs,ys,omega,epsilon,wpml,sigmaMax,ray,speed,fquadorder,option)
%% Function to assemble the right hand side with singularity treatment (ST):
%         -\Delta u - (omega/c)^2 u = 2 \nabla u_b \cdot \nabla \chi + u_b \Delta \chi,     in D
%                                                u = 0               on \partial D
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% INPUT:
%
%   node: N x 2 matrix that contains the physical position of each node
%         node(:,1) provides the x coordinate
%         node(:,2) provides the y coordinate
%
%   elem: NT x 3 matrix that contains the indices of the nodes for each
%         triangle element
%
%   (xs, ys): source location;   omega: frequency;
%
%   epsilon: cut-off support size
%
%   wpml: width of PML;  sigmaMax: max absorption
%
%   ray: ray information;  speed: wave speed
%
%   fquadorder: The order of numerical quadrature
%
%   option: different types -- homogenenous, gravity
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% OUTPUT:
%
%   b: Ndof x 1 Galerkin projection of the source
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% fprintf('Assembling the right-hand side \n');

% source = @(x) -1i*10*pi*exp(1i*10*pi*sqrt(x(:,1).^2+x(:,2).^2))./sqrt(x(:,1).^2+x(:,2).^2);



%% FEM set up
N = size(node,1);        % number of grid points
NT = size(elem,1);       % number of triangle elements
c = speed(node);         % medium speed
k = omega./c;            % wavenumber

xmax = max(node(:,1));
xmin = min(node(:,1));
ymax = max(node(:,2));
ymin = min(node(:,2));
h = (xmax - xmin)/(round(sqrt(N)) - 1);


%% PML set up
sigmaPML_x = @(x)sigmaMax*( (x-xmin-wpml).^2.*(x < xmin + wpml) + ...
    (x-(xmax-wpml)).^2.*(x > xmax - wpml))/wpml^2;
sigmaPML_y = @(y) sigmaMax*( (y-ymin-wpml).^2.*(y < ymin + wpml) ...
    + (y-(ymax-wpml)).^2.*(y > ymax - wpml))/wpml^2;
% s_xy = @(x,y) ((1+1i*sigmaPML_x(x)/omega).*(1+1i*sigmaPML_y(y)/omega));    %% 1/(s1*s2)
s_xy = @(p) ((1+1i*sigmaPML_x(p(:,1))/omega).*(1+1i*sigmaPML_y(p(:,2))/omega));    %% 1/(s1*s2)



%% Numerical Quadrature
[lambda,weight] = quadpts(fquadorder);
phi = lambda;           % linear bases
nQuad = size(lambda,1);


%% Compute geometric quantities and gradient of local basis
[~,area] = gradbasis(node,elem);


%% Babich pre-processing
Bx = []; By = []; phase = [];  amplitude = [];
if  iscell(option) && strcmp(option{1}, 'Babich')
    
    if strcmp(option{2}, 'CGV')
        switch round(omega/(pi))
            case 120
                load('Babich_CGV_30.mat');
            case 160
                load('Babich_CGV_40.mat');
            case 240
                load('Babich_CGV_60.mat');
            case 320
                load('Babich_CGV_80.mat');
            case 400
                load('Babich_CGV_100.mat');
            case 500
                load('Babich_CGV_125.mat');
            case 600
                load('Babich_CGV_150.mat');
        end
    end
    
    if strcmp(option{2}, 'Homo')
        switch round(omega/(pi))
            case 100
                load('Babich_Homo_25.mat');
            case 160
                load('Babich_Homo_40.mat');
            case 240
                load('Babich_Homo_60.mat');
            case 400
                load('Babich_Homo_100.mat');
            case 600
                load('Babich_Homo_150.mat');
        end
    end
    
    a = 1/2;
    CompressRatio = round(Bh0/(h/2));
    Bh = 1/round( 1/(Bh0/CompressRatio) );
    Bx = -a: Bh : a;  By = -a: Bh : a;
    [BX0, BY0] = meshgrid(Bx0, By0);
    [BX, BY] = meshgrid(Bx, By);
    
    %% refined amplitude
    DD1 = interp2(BX0,BY0,D1,BX,BY,'spline');
    DD2 = interp2(BX0,BY0,D2,BX,BY,'spline');
    
    % gradient
    [D1x,D1y] = num_derivative(D1,Bh0,4);
    [D2x,D2y] = num_derivative(D2,Bh0,4);
    DD1x = interp2(BX0,BY0,D1x,BX,BY,'spline');
    DD1y = interp2(BX0,BY0,D1y,BX,BY,'spline');
    DD2x = interp2(BX0,BY0,D2x,BX,BY,'spline');
    DD2y = interp2(BX0,BY0,D2y,BX,BY,'spline');
    amplitude = [DD1(:), DD1x(:), DD1y(:), DD2(:), DD2x(:), DD2y(:)];
    
    %% refined phase
    if strcmp(option{3}, 'numerical_phase')
        ttao = interp2(BX0,BY0,tao,BX,BY,'spline');
        mid = round(size(tao,1)/2);
        taox = tao2x ./ (2*tao);   taox(mid, mid) = 0;
        taoy = tao2y ./ (2*tao);   taoy(mid, mid) = 0;
        ttaox = interp2(BX0,BY0,taox,BX,BY,'spline'); % refined phase
        ttaoy = interp2(BX0,BY0,taoy,BX,BY,'spline'); % refined phase
        phase = [ttao(:), ttaox(:), ttaoy(:)];
    end
    
end


%% Assembling the RHS: ray could be a N x Nray matrix or N x 1 cell

%% ray is N x Nray matrix: each grid point has the same number of rays
if ~iscell(ray)
    
    Nray = size(ray,2);
    Ndof = N*Nray;          % degree of freedom
    kk = repmat(k,1,Nray);
    reparea = repmat(area,Nray,1);
    
    % Assemble right-hand side
    bt = zeros(NT*Nray,3);       % the right hand side
    b = zeros(Ndof,1);
    
    for p = 1:nQuad
        % quadrature points in the x-y coordinate
        pxy = lambda(p,1)*node(elem(:,1),:) ...
            + lambda(p,2)*node(elem(:,2),:) ...
            + lambda(p,3)*node(elem(:,3),:);
        reppxy = repmat(pxy,Nray,1);
        sxy = s_xy(reppxy);
        
        [ub, ub_g1, ub_g2] = Babich_expansion(xs,ys,pxy,omega,option,Bx,By,phase,amplitude);
        fpxy = singularity_RHS(epsilon,xs,ys,pxy,ub,ub_g1,ub_g2);
        fp = repmat(fpxy,Nray,1).*sxy;
        
        for i = 1:3
            gradtempi = - ray(elem(:,i),:);
            gradtempi = gradtempi(:);
            gradtempi = [real(gradtempi), imag(gradtempi)];
            fphasei = gradtempi(:,1).*reppxy(:,1) + gradtempi(:,2).*reppxy(:,2);
            kki = kk(elem(:,i),:);
            kki = kki(:);
            phasei = exp(1i*kki.*fphasei);
            bt(:,i) = bt(:,i) + weight(p)*phi(p,i)*phasei.*fp;
        end
    end
    
    bt = bt.*repmat(reparea,1,3);
    for ni = 1:Nray
        ii = (ni-1)*NT+1:1:ni*NT;
        jj = (ni-1)*N+1:1:ni*N;
        btii = bt(ii,:);
        b(jj) = accumarray(elem(:),btii(:),[N 1]);
    end
    
    
else
    %% ray is N x 1 cell: each grid point may have different number of rays
    
    ray_num = zeros(N,1);     % number of rays at each grid point
    ray_dof = zeros(N,1);     % ray_dof(n) = sum(ray_num(1:n))
    
    temp = 0;
    for n = 1:N
        ray_num(n) = size(ray{n},2);
        ray_dof(n) = temp + ray_num(n);
        temp = ray_dof(n);
    end
    
    Ndof = temp;              % total degree of freedom
    
    % Assemble right-hand side
    b = zeros(Ndof,1);
    
    for nt = 1:NT
        for p = 1:nQuad
            % quadrature points in the x-y coordinate
            pxy = lambda(p,1)*node(elem(nt,1),:) ...
                + lambda(p,2)*node(elem(nt,2),:) ...
                + lambda(p,3)*node(elem(nt,3),:);
            sxy = s_xy(pxy);
            [ub, ub_g1, ub_g2] = Babich_expansion(xs,ys,pxy,omega,option,Bx,By,phase,amplitude);
            fpxy = singularity_RHS(epsilon,xs,ys,pxy,ub,ub_g1,ub_g2);
            fp = fpxy.*sxy;
            
            if norm(fp)
                for i = 1:3
                    ei = elem(nt,i);    % the ei'th grid point corresponding to the i'th vertix of element nt
                    ni = ray_num(ei);   % number of rays crossing at grid point ei
                    for nii = 1: ni
                        gradtempi = - ray{ei}(nii);
                        gradtempi = [real(gradtempi), imag(gradtempi)];
                        fphasei = gradtempi(1)*pxy(1) + gradtempi(2)*pxy(2);
                        ki = k(ei);
                        phasei = exp(1i*ki*fphasei);
                        ii = ray_dof(ei) - ni + nii;
                        b(ii) = b(ii) + weight(p)*phi(p,i)*phasei*fp*area(nt);   % right hand side
                    end
                end
            end
        end
    end
    
    
end







% clear area bt btii elem fp fphasei gradtempi ii jj k kk kki;
% clear node phasei pcy pxy ray reparea reppxy;


